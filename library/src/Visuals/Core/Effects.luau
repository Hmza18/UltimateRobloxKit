--!strict
-- Effect lifecycle manager (pure Luau). Every world effect - a burst, an aura, a trail - goes
-- through spawn(), which decides whether it may play and guarantees it is cleaned up:
--   * distance: beyond the profile's maxDistance nothing plays; counts scale down before that
--   * offscreen: one-shot effects the viewer cannot see are skipped (loops still attach)
--   * throttle: the same effect id cannot restart more often than its minInterval (rapid taps)
--   * budgets: live effect count and estimated live particles stay under the quality profile;
--     a higher-priority effect evicts the oldest lower-priority one instead of being refused
--   * cleanup: one-shots end after `duration`; stop(), stopOwner() and stopAll() end anything now
-- The caller's `build` creates the real instances and returns a destroy function, so this module
-- never touches Roblox and can be tested with fakes.

local Clock = require("./Clock")
local Quality = require("./Quality")

export type Position = { number } -- { x, y, z }

export type Request = {
	id: string,
	particles: number?, -- estimated live particles at full quality (default 0)
	lights: number?, -- dynamic lights it creates (default 0)
	duration: number?, -- seconds until a one-shot is destroyed; nil for looping effects
	looping: boolean?,
	position: Position?,
	priority: number?, -- default 0; essential feedback (rare reveals) should use 10+
	owner: any?, -- anything; stopOwner(owner) ends every effect tagged with it
	minInterval: number?, -- seconds between starts of this id (default 0)
	-- Creates the effect. `scale` is the 0..1 count multiplier from distance; returns destroy.
	build: (scale: number, profile: Quality.Profile) -> (() -> ())?,
}

export type Handle = {
	id: string,
	stop: () -> (),
	isAlive: () -> boolean,
}

export type Stats = {
	live: number,
	particles: number,
	lights: number,
	spawned: number,
	evicted: number,
	rejected: { [string]: number }, -- reason -> count
}

export type Host = {
	clock: Clock.Clock,
	profile: () -> Quality.Profile,
	viewer: (() -> Position?)?, -- camera position
	visible: ((position: Position) -> boolean)?, -- true when on screen (or unknown)
}

type Live = {
	handle: Handle,
	id: string,
	particles: number,
	lights: number,
	priority: number,
	owner: any?,
	destroy: (() -> ())?,
	cancelTimer: (() -> ())?,
	alive: boolean,
	order: number,
}

export type Effects = {
	spawn: (self: Effects, request: Request) -> (Handle?, string?),
	stopOwner: (self: Effects, owner: any) -> number,
	stopAll: (self: Effects) -> number,
	stopId: (self: Effects, id: string) -> number,
	stats: (self: Effects) -> Stats,
	resetStats: (self: Effects) -> (),
}

local Effects = {}

local function distance(a: Position, b: Position): number
	local dx, dy, dz = a[1] - b[1], a[2] - b[2], a[3] - b[3]
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

function Effects.new(host: Host): Effects
	local live: { Live } = {}
	local lastStart: { [string]: number } = {}
	local order = 0
	local stats: Stats = { live = 0, particles = 0, lights = 0, spawned = 0, evicted = 0, rejected = {} }
	local self: Effects

	local function reject(reason: string): (Handle?, string?)
		stats.rejected[reason] = (stats.rejected[reason] or 0) + 1
		return nil, reason
	end

	local function remove(entry: Live)
		if not entry.alive then
			return
		end
		entry.alive = false
		if entry.cancelTimer then
			entry.cancelTimer()
			entry.cancelTimer = nil
		end
		local index = table.find(live, entry)
		if index then
			table.remove(live, index)
		end
		stats.live -= 1
		stats.particles -= entry.particles
		stats.lights -= entry.lights
		if entry.destroy then
			local ok, err = pcall(entry.destroy)
			if not ok then
				host.clock.onError("[UVK] effect cleanup failed: " .. tostring(err))
			end
			entry.destroy = nil
		end
	end

	-- Frees room for an effect of `priority` by ending the oldest effect of lower priority.
	local function evictOne(priority: number): boolean
		local victim: Live? = nil
		for _, entry in live do
			if entry.priority < priority then
				if
					victim == nil
					or entry.priority < victim.priority
					or (entry.priority == victim.priority and entry.order < victim.order)
				then
					victim = entry
				end
			end
		end
		if victim then
			stats.evicted += 1
			remove(victim)
			return true
		end
		return false
	end

	local function stopWhere(test: (entry: Live) -> boolean): number
		local n = 0
		for _, entry in table.clone(live) do
			if test(entry) then
				remove(entry)
				n += 1
			end
		end
		return n
	end

	self = {
		spawn = function(_self: Effects, request: Request): (Handle?, string?)
			local profile = host.profile()
			local priority = request.priority or 0
			local scale = 1
			if request.position then
				local viewer = if host.viewer then host.viewer() else nil
				if viewer then
					scale = Quality.distanceScale(profile, distance(viewer, request.position))
					if scale <= 0 then
						return reject("distance")
					end
				end
				if not request.looping and host.visible and not host.visible(request.position) then
					return reject("offscreen")
				end
			end
			local now = host.clock:now()
			local interval = request.minInterval or 0
			local last = lastStart[request.id]
			if interval > 0 and last ~= nil and now - last < interval then
				return reject("throttled")
			end
			local particles = math.ceil((request.particles or 0) * profile.particleScale * scale)
			local lights = if profile.lights then request.lights or 0 else 0
			while stats.live >= profile.maxEffects do
				if not evictOne(priority) then
					return reject("effects")
				end
			end
			while particles > 0 and stats.particles + particles > profile.maxParticles do
				if not evictOne(priority) then
					return reject("particles")
				end
			end
			if lights > 0 and stats.lights + lights > profile.maxLights then
				lights = 0 -- the effect still plays; its build should skip lights past the budget
			end
			lastStart[request.id] = now

			local ok, destroy = pcall(request.build, scale, profile)
			if not ok then
				host.clock.onError("[UVK] effect " .. request.id .. " failed to build: " .. tostring(destroy))
				return reject("error")
			end
			order += 1
			local entry: Live
			local handle: Handle = {
				id = request.id,
				stop = function()
					remove(entry)
				end,
				isAlive = function(): boolean
					return entry.alive
				end,
			}
			entry = {
				handle = handle,
				id = request.id,
				particles = particles,
				lights = lights,
				priority = priority,
				owner = request.owner,
				destroy = destroy,
				cancelTimer = nil :: (() -> ())?,
				alive = true,
				order = order,
			}
			table.insert(live, entry)
			stats.live += 1
			stats.particles += particles
			stats.lights += lights
			stats.spawned += 1
			if not request.looping then
				entry.cancelTimer = host.clock:after(request.duration or 1, function()
					entry.cancelTimer = nil
					remove(entry)
				end)
			end
			return handle, nil
		end,
		stopOwner = function(_self: Effects, owner: any): number
			return stopWhere(function(entry: Live): boolean
				return entry.owner == owner
			end)
		end,
		stopAll = function(_self: Effects): number
			return stopWhere(function(): boolean
				return true
			end)
		end,
		stopId = function(_self: Effects, id: string): number
			return stopWhere(function(entry: Live): boolean
				return entry.id == id
			end)
		end,
		stats = function(_self: Effects): Stats
			local copy = table.clone(stats)
			copy.rejected = table.clone(stats.rejected)
			return copy
		end,
		resetStats = function(_self: Effects)
			stats.spawned, stats.evicted, stats.rejected = 0, 0, {}
		end,
	}
	return self
end

return Effects
