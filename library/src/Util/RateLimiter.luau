--!strict
-- Token-bucket rate limiter. Pure Luau: no Roblox globals and no clock access.
-- Callers pass `now` (os.clock() on Roblox), which keeps the logic deterministic and testable.

export type Options = {
	capacity: number, -- most tokens a bucket holds, which is the allowed burst
	refillPerSecond: number, -- tokens added back each second
}

export type Bucket = { tokens: number, updatedAt: number }

export type Limiter = {
	allow: (self: Limiter, key: string, now: number, cost: number?) -> boolean,
	forget: (self: Limiter, key: string) -> (),
	size: (self: Limiter) -> number,
}

local RateLimiter = {}

local function assertOptions(options: Options)
	assert(type(options.capacity) == "number" and options.capacity > 0, "capacity must be a positive number")
	assert(type(options.refillPerSecond) == "number" and options.refillPerSecond >= 0, "refill must be >= 0")
end

function RateLimiter.newBucket(options: Options, now: number): Bucket
	assertOptions(options)
	return { tokens = options.capacity, updatedAt = now }
end

-- Refills the bucket for the time since its last update, then tries to spend `cost` tokens (default 1).
-- Returns whether the request is allowed and the new bucket. The input bucket is never modified.
function RateLimiter.take(bucket: Bucket, options: Options, now: number, cost: number?): (boolean, Bucket)
	local price = cost or 1
	-- A clock that moves backwards must never mint tokens.
	local elapsed = math.max(0, now - bucket.updatedAt)
	local updatedAt = math.max(now, bucket.updatedAt)
	local tokens = math.min(options.capacity, bucket.tokens + elapsed * options.refillPerSecond)
	if tokens >= price then
		return true, { tokens = tokens - price, updatedAt = updatedAt }
	end
	return false, { tokens = tokens, updatedAt = updatedAt }
end

-- A set of buckets keyed by string, for example one per player.
function RateLimiter.new(options: Options): Limiter
	assertOptions(options)
	local buckets: { [string]: Bucket } = {}

	local function allow(_self: Limiter, key: string, now: number, cost: number?): boolean
		local bucket = buckets[key] or RateLimiter.newBucket(options, now)
		local allowed, nextBucket = RateLimiter.take(bucket, options, now, cost)
		buckets[key] = nextBucket
		return allowed
	end

	local function forget(_self: Limiter, key: string)
		buckets[key] = nil
	end

	local function size(_self: Limiter): number
		local count = 0
		for _ in buckets do
			count += 1
		end
		return count
	end

	return { allow = allow, forget = forget, size = size }
end

return RateLimiter
