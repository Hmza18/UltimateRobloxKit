--!strict
local RateLimiter = require("../src/shared/Logic/RateLimiter")
local t = require("./lib/t")

local OPTIONS = { capacity = 3, refillPerSecond = 1 }

return {
	["a full bucket allows a burst up to capacity"] = function()
		local limiter = RateLimiter.new(OPTIONS)
		t.truthy(limiter:allow("a", 0))
		t.truthy(limiter:allow("a", 0))
		t.truthy(limiter:allow("a", 0))
		t.falsy(limiter:allow("a", 0), "fourth request")
	end,

	["tokens refill over time but never above capacity"] = function()
		local bucket = RateLimiter.newBucket(OPTIONS, 0)
		local _, drained = RateLimiter.take(bucket, OPTIONS, 0, 3)
		t.equal(drained.tokens, 0)
		local allowed, refilled = RateLimiter.take(drained, OPTIONS, 1.5)
		t.truthy(allowed)
		t.near(refilled.tokens, 0.5)
		local _, capped = RateLimiter.take(refilled, OPTIONS, 100, 0)
		t.equal(capped.tokens, 3)
	end,

	["a clock moving backwards does not add tokens"] = function()
		local bucket = { tokens = 0, updatedAt = 10 }
		local allowed, nextBucket = RateLimiter.take(bucket, OPTIONS, 5)
		t.falsy(allowed)
		t.equal(nextBucket.tokens, 0)
		t.equal(nextBucket.updatedAt, 10)
	end,

	["take does not modify its input"] = function()
		local bucket = RateLimiter.newBucket(OPTIONS, 0)
		RateLimiter.take(bucket, OPTIONS, 0)
		t.equal(bucket.tokens, 3)
	end,

	["keys are independent and can be forgotten"] = function()
		local limiter = RateLimiter.new({ capacity = 1, refillPerSecond = 0 })
		t.truthy(limiter:allow("a", 0))
		t.falsy(limiter:allow("a", 0))
		t.truthy(limiter:allow("b", 0))
		t.equal(limiter:size(), 2)
		limiter:forget("a")
		t.equal(limiter:size(), 1)
		t.truthy(limiter:allow("a", 0), "a starts full again")
	end,

	["invalid options are rejected"] = function()
		t.throws(function()
			RateLimiter.new({ capacity = 0, refillPerSecond = 1 })
		end)
		t.throws(function()
			RateLimiter.new({ capacity = 1, refillPerSecond = -1 })
		end)
	end,
}
